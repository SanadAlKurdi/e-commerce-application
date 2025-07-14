import React, { useState, useEffect } from 'react';
import {
    View,
    TextInput,
    Button,
    StyleSheet,
    Image,
    ScrollView,
    Alert,
} from 'react-native';
import { launchImageLibrary } from 'react-native-image-picker';
import storage from '@react-native-firebase/storage';
import { updateProduct } from '../services/firebaseService';

export default function EditProductScreen({ route, navigation }: any) {
    const { product } = route.params;
    const [title, setTitle] = useState(product.title);
    const [description, setDescription] = useState(product.description);
    const [price, setPrice] = useState(String(product.price));
    const [stock, setStock] = useState(String(product.stock));
    const [category, setCategory] = useState(product.category);
    const [image, setImage] = useState<any>({ uri: product.imageUrl });
    const [uploading, setUploading] = useState(false);

    const pickImage = async () => {
        const result = await launchImageLibrary({ mediaType: 'photo' });
        if (result.assets && result.assets.length > 0) {
            setImage(result.assets[0]);
        }
    };

    const handleUpdate = async () => {
        setUploading(true);
        try {
            let imageUrl = product.imageUrl;

            if (image?.uri && image.uri !== product.imageUrl) {
                const filename = image.uri.substring(image.uri.lastIndexOf('/') + 1);
                const ref = storage().ref(`/products/${filename}`);
                await ref.putFile(image.uri);
                imageUrl = await ref.getDownloadURL();
            }

            await updateProduct(product.id, {
                title,
                description,
                price: parseFloat(price),
                stock: parseInt(stock),
                category,
                imageUrl,
            });

            Alert.alert('Success', 'Product updated');
            navigation.goBack();
        } catch (error: any) {
            Alert.alert('Error', error.message);
        } finally {
            setUploading(false);
        }
    };

    return (
        <ScrollView contentContainerStyle={styles.container}>
            <TextInput placeholder="Title" value={title} onChangeText={setTitle} style={styles.input} />
            <TextInput placeholder="Description" value={description} onChangeText={setDescription} style={styles.input} multiline />
            <TextInput placeholder="Price" value={price} onChangeText={setPrice} style={styles.input} keyboardType="decimal-pad" />
            <TextInput placeholder="Stock" value={stock} onChangeText={setStock} style={styles.input} keyboardType="numeric" />
            <TextInput placeholder="Category" value={category} onChangeText={setCategory} style={styles.input} />
            <Button title="Change Image" onPress={pickImage} />
            {image?.uri && <Image source={{ uri: image.uri }} style={styles.image} />}
            <Button title="Update Product" onPress={handleUpdate} disabled={uploading} />
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    container: { padding: 20 },
    input: {
        borderBottomWidth: 1,
        marginBottom: 12,
        fontSize: 16,
        padding: 8,
    },
    image: {
        width: '100%',
        height: 200,
        marginVertical: 10,
    },
});
